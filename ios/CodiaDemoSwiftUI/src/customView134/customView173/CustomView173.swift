//
//  CustomView173.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView173: View {
    @State public var image122Path: String = "image122_4669"
    @State public var text91Text: String = "Dark Mode"
    @State public var image123Path: String = "image123_4679"
    var body: some View {
        HStack(alignment: .center) {
            Image(image122Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView174(
                text91Text: text91Text,
                image123Path: image123Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView173_Previews: PreviewProvider {
    static var previews: some View {
        CustomView173()
    }
}
