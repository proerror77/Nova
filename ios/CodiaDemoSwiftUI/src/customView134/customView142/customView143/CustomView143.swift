//
//  CustomView143.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView143: View {
    @State public var image110Path: String = "image110_4590"
    @State public var text85Text: String = "Profile Settings"
    @State public var image111Path: String = "image111_4600"
    var body: some View {
        HStack(alignment: .center) {
            Image(image110Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView144(
                text85Text: text85Text,
                image111Path: image111Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView143_Previews: PreviewProvider {
    static var previews: some View {
        CustomView143()
    }
}
