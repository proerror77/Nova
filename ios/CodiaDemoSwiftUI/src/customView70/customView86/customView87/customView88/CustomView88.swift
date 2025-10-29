//
//  CustomView88.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView88: View {
    @State public var image76Path: String = "image76_4451"
    @State public var text57Text: String = "William Rhodes"
    @State public var text58Text: String = "10m"
    @State public var image77Path: String = "image77_4455"
    var body: some View {
        HStack(alignment: .center, spacing: 106) {
            CustomView89(
                image76Path: image76Path,
                text57Text: text57Text,
                text58Text: text58Text)
            Image(image77Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 5.997, height: 7.996, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView88_Previews: PreviewProvider {
    static var previews: some View {
        CustomView88()
    }
}
