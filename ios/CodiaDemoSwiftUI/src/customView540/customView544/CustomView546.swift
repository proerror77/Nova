//
//  CustomView546.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView546: View {
    @State public var image376Path: String = "image376_41857"
    @State public var text258Text: String = "Account_one (Primary)"
    @State public var image377Path: String = "image377_41859"
    var body: some View {
        HStack(alignment: .center, spacing: 88) {
            CustomView547(
                image376Path: image376Path,
                text258Text: text258Text)
            Image(image377Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18.06, height: 18.06, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView546_Previews: PreviewProvider {
    static var previews: some View {
        CustomView546()
    }
}
