//
//  CustomView292.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView292: View {
    @State public var text162Text: String = "Liam"
    @State public var text163Text: String = "Hello, how are you bro~"
    @State public var text164Text: String = "09:41 PM"
    @State public var image207Path: String = "image207_I49684966"
    @State public var text165Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView293(
                text162Text: text162Text,
                text163Text: text163Text)
                .frame(width: 161, height: 46)
            CustomView294(
                text164Text: text164Text,
                image207Path: image207Path,
                text165Text: text165Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView292_Previews: PreviewProvider {
    static var previews: some View {
        CustomView292()
    }
}
