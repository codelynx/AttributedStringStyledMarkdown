//
//  Created by Frank Rausch on 2021-11-15.
//

import SwiftUI
#if canImport(UIKit)
extension UIFont: @unchecked @retroactive Sendable {}
import UIKit
#elseif canImport(AppKit)
extension NSFont: @unchecked @retroactive Sendable {}
import AppKit
#endif

extension NSMutableParagraphStyle: @unchecked Sendable {}
extension NSParagraphStyle: @unchecked @retroactive Sendable {}

fileprivate enum MarkdownStyledBlock: Equatable {
    case generic
    case headline(Int)
    case paragraph
    case unorderedListElement
    case orderedListElement(Int)
    case blockquote
    case code(String?)
}

// MARK: -

extension AttributedString {
    
    #if canImport(UIKit)
    typealias XFont = UIFont
    #elseif canImport(AppKit)
    typealias XFont = NSFont
    #endif
    
    init(styledMarkdown markdownString: String, fontSize: CGFloat = XFont.preferredFont(forTextStyle: .body).pointSize, baseURL: URL? = nil) throws {
        
        XFont.preferredFont(forTextStyle: .body)
        
        var s = try AttributedString(markdown: markdownString, options: .init(allowsExtendedAttributes: true, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible), baseURL: baseURL)
        
        // Looking at the AttributedString’s raw structure helps with understanding the following code.
        print(s)
        
        // Set base font and paragraph style for the whole string
        s.font = .systemFont(ofSize: fontSize)
        s.paragraphStyle = defaultParagraphStyle
        
        // Will respect dark mode automatically
        #if canImport(UIKit)
        s.foregroundColor = Color(UIColor.label)
        #elseif canImport(AppKit)
        s.foregroundColor = Color(NSColor.labelColor)
        #endif

        // MARK: Inline Intents
        let inlineIntents: [InlinePresentationIntent] = [.emphasized, .stronglyEmphasized, .code, .strikethrough, .softBreak, .lineBreak, .inlineHTML, .blockHTML]
        
        for inlineIntent in inlineIntents {
            
            var sourceAttributeContainer = AttributeContainer()
            sourceAttributeContainer.inlinePresentationIntent = inlineIntent
            
            var targetAttributeContainer = AttributeContainer()
            switch inlineIntent {
            case .emphasized:
                #if canImport(UIKit)
                targetAttributeContainer.font = UIFont.italicSystemFont(ofSize: fontSize)
                #elseif canImport(AppKit)
                targetAttributeContainer.font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: fontSize), toHaveTrait: .italicFontMask)
                #endif
            case .stronglyEmphasized:
                targetAttributeContainer.font = .systemFont(ofSize: fontSize, weight: .bold)
            case .code:
                targetAttributeContainer.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
                #if os(iOS)
                targetAttributeContainer.backgroundColor = .secondarySystemBackground
                #else
                targetAttributeContainer.backgroundColor = Color.secondary.opacity(0.1)
                #endif
            case .strikethrough:
                targetAttributeContainer.strikethroughStyle = .single
            case .softBreak:
                break // TODO: Implement
            case .lineBreak:
                break // TODO: Implement
            case .inlineHTML:
                break // TODO: Implement
            case .blockHTML:
                break // TODO: Implement
            default:
                break
            }

            s = s.replacingAttributes(sourceAttributeContainer, with: targetAttributeContainer)
        }

        // MARK: Blocks

        // Accessing via dynamic lookup key path (\.presentationIntent) triggers a warning on Xcode 13.1, so we use the verbose way: AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self

        // We use .reversed() iteration to be able to add characters to the string without breaking ranges.

        var previousListID = 0

        for (intentBlock, intentRange) in s.runs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self].reversed() {
            guard let intentBlock = intentBlock else { continue }

            var block: MarkdownStyledBlock = .generic
            var currentElementOrdinal: Int = 0

            var currentListID = 0

            for intent in intentBlock.components {
                switch intent.kind {
                case .paragraph:
                    if block == .generic {
                        block = .paragraph
                    }
                case .header(level: let level):
                    block = .headline(level)
                case .orderedList:
                    block = .orderedListElement(currentElementOrdinal)
                    currentListID = intent.identity
                case .unorderedList:
                    block = .unorderedListElement
                    currentListID = intent.identity
                case .listItem(ordinal: let ordinal):
                    currentElementOrdinal = ordinal
                    if block != .unorderedListElement {
                        block = .orderedListElement(ordinal)
                    }
                case .codeBlock(languageHint: let languageHint):
                    block = .code(languageHint)
                case .blockQuote:
                    block = .blockquote
                case .thematicBreak:
                    break // This is ---- in Markdown.
                case .table(columns: _):
                    break
                case .tableHeaderRow:
                    break
                case .tableRow(rowIndex: _):
                    break
                case .tableCell(columnIndex: _):
                    break
                @unknown default:
                    break
                }
            }

            switch block {
            case .generic:
                assertionFailure(intentBlock.debugDescription)
            case .headline(let level):
                switch level {
                case 1:
                    s[intentRange].font = .systemFont(ofSize: 30, weight: .heavy)
                case 2:
                    s[intentRange].font = .systemFont(ofSize: 20, weight: .heavy)
                case 3:
                    s[intentRange].font = .systemFont(ofSize: 15, weight: .heavy)
                default:
                    // TODO: Handle H4 to H6
                    s[intentRange].font = .systemFont(ofSize: 15, weight: .heavy)
                }
            case .paragraph:
                break
            case .unorderedListElement:
                s.characters.insert(contentsOf: "•\t", at: intentRange.lowerBound)
                s[intentRange].paragraphStyle = previousListID == currentListID ? listParagraphStyle : lastElementListParagraphStyle
            case .orderedListElement(let ordinal):
                s.characters.insert(contentsOf: "\(ordinal).\t", at: intentRange.lowerBound)
                s[intentRange].paragraphStyle = previousListID == currentListID ? listParagraphStyle : lastElementListParagraphStyle
            case .blockquote:
                s[intentRange].paragraphStyle = defaultParagraphStyle
                #if canImport(UIKit)
                s[intentRange].foregroundColor = Color(UIColor.secondaryLabel)
                #elseif canImport(AppKit)
                s[intentRange].foregroundColor = Color(NSColor.secondaryLabelColor)
                #endif
            case .code:
                s[intentRange].font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                s[intentRange].paragraphStyle = codeParagraphStyle
            }

            // Remember the list ID so we can check if it’s identical in the next block
            previousListID = currentListID

            // MARK: Add line breaks to separate blocks

            if intentRange.lowerBound != s.startIndex {
                s.characters.insert(contentsOf: "\n", at: intentRange.lowerBound)
            }
        }

        self = s
    }
}

fileprivate let defaultParagraphStyle: NSParagraphStyle = {
    var paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacing = 10.0
    paragraphStyle.minimumLineHeight = 20.0
    return paragraphStyle
}()


fileprivate let listParagraphStyle: NSMutableParagraphStyle = {
    var paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 20)]
    paragraphStyle.headIndent = 20
    paragraphStyle.minimumLineHeight = 20.0
    return paragraphStyle
}()

fileprivate let lastElementListParagraphStyle: NSMutableParagraphStyle = {
    var paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 20)]
    paragraphStyle.headIndent = 20
    paragraphStyle.minimumLineHeight = 20.0
    paragraphStyle.paragraphSpacing = 20.0 // The last element in a list needs extra paragraph spacing
    return paragraphStyle
}()


fileprivate let codeParagraphStyle: NSParagraphStyle = {
    var paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.minimumLineHeight = 20.0
    paragraphStyle.firstLineHeadIndent = 20
    paragraphStyle.headIndent = 20
    return paragraphStyle
}()
