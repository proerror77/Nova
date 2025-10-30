//
//  CustomView270.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView270: View {
    @State public var image194Path: String = "image194_4921"
    @State public var text149Text: String = "Liam"
    @State public var text150Text: String = "Hello, how are you bro~"
    @State public var text151Text: String = "09:41 PM"
    @State public var image195Path: String = "image195_4930"
    @State public var text152Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(image194Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView271(
                text149Text: text149Text,
                text150Text: text150Text,
                text151Text: text151Text,
                image195Path: image195Path,
                text152Text: text152Text)
                .frame(height: 72)
        }
        .frame(width: 356, height: 72, alignment: .topLeading)
    }
}

struct CustomView270_Previews: PreviewProvider {
    static var previews: some View {
        CustomView270()
    }
}
