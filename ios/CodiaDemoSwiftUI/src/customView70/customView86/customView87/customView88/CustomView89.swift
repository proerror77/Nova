//
//  CustomView89.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView89: View {
    @State public var image76Path: String = "image76_4451"
    @State public var text57Text: String = "William Rhodes"
    @State public var text58Text: String = "10m"
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            Image(image76Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15, alignment: .topLeading)
                .cornerRadius(7.5)
            CustomView90(
                text57Text: text57Text,
                text58Text: text58Text)
                .frame(width: 40)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView89_Previews: PreviewProvider {
    static var previews: some View {
        CustomView89()
    }
}
