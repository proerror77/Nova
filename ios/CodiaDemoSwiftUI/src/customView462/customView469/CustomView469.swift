//
//  CustomView469.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView469: View {
    @State public var text235Text: String = "All"
    @State public var text236Text: String = "Video"
    @State public var text237Text: String = "Photos"
    @State public var image291Path: String = "image291_41458"
    var body: some View {
        HStack(alignment: .center, spacing: 46) {
            CustomView470(
                text235Text: text235Text,
                text236Text: text236Text,
                text237Text: text237Text)
            Image(image291Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(width: 336, height: 45, alignment: .topLeading)
    }
}

struct CustomView469_Previews: PreviewProvider {
    static var previews: some View {
        CustomView469()
    }
}
