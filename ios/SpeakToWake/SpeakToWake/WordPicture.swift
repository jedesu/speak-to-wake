import SwiftUI
import UIKit
import WakeCore

/// A word's flat 2D picture (Microsoft Fluent Emoji, MIT license, in Pictures.xcassets),
/// falling back to its emoji. Shows nothing for words without a picture (的, 了, 吗...).
struct WordPicture: View {
    let word: Word
    var size: CGFloat = 64

    static func exists(for word: Word) -> Bool {
        UIImage(named: "pic-\(word.conceptId)") != nil || AppContent.library.concept(for: word)?.emoji != nil
    }

    var body: some View {
        if UIImage(named: "pic-\(word.conceptId)") != nil {
            Image("pic-\(word.conceptId)")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("Picture of \(AppContent.library.concept(for: word)?.english ?? word.text)")
        } else if let emoji = AppContent.library.concept(for: word)?.emoji {
            Text(emoji)
                .font(.system(size: size * 0.85))
                .frame(width: size, height: size)
                .accessibilityLabel("Picture of \(AppContent.library.concept(for: word)?.english ?? word.text)")
        }
    }
}

/// The picture on a soft chip-colored circle, used for hints.
struct WordPictureBubble: View {
    let word: Word
    var size: CGFloat = 112

    var body: some View {
        WordPicture(word: word, size: size * 0.62)
            .frame(width: size, height: size)
            .background(Theme.chip, in: .circle)
    }
}
