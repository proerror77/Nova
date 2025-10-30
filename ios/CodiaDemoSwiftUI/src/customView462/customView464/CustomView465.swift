//
//  CustomView465.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView465: View {
    @State public var image288Path: String = "image288_41441"
    @State public var text233Text: String = "All"
    @State public var image289Path: String = "image289_41444"
    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            Image(image288Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20, alignment: .topLeading)
            CustomView466(
                text233Text: text233Text,
                image289Path: image289Path)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 90, alignment: .leading)
    }
}

struct CustomView465_Previews: PreviewProvider {
    static var previews: some View {
        CustomView465()
    }
}
