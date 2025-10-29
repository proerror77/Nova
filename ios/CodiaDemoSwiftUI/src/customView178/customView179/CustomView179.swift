//
//  CustomView179.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView179: View {
    @State public var text92Text: String = "Bruce Li"
    @State public var image124Path: String = "image124_I468441875"
    @State public var image125Path: String = "image125_4685"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView180(
                text92Text: text92Text,
                image124Path: image124Path)
                .frame(width: 100, height: 16)
            Image(image125Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView179_Previews: PreviewProvider {
    static var previews: some View {
        CustomView179()
    }
}
