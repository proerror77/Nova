//
//  CustomView464.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView464: View {
    @State public var image288Path: String = "image288_41441"
    @State public var text233Text: String = "All"
    @State public var image289Path: String = "image289_41444"
    @State public var image290Path: String = "image290_41448"
    @State public var text234Text: String = "Drafts"
    var body: some View {
        HStack(alignment: .center, spacing: 183) {
            CustomView465(
                image288Path: image288Path,
                text233Text: text233Text,
                image289Path: image289Path)
                .frame(width: 90)
            CustomView467(
                image290Path: image290Path,
                text234Text: text234Text)
                .frame(width: 75, height: 28)
        }
        .frame(width: 348, height: 28, alignment: .topLeading)
    }
}

struct CustomView464_Previews: PreviewProvider {
    static var previews: some View {
        CustomView464()
    }
}
