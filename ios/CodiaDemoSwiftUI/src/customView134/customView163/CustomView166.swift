//
//  CustomView166.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView166: View {
    @State public var text89Text: String = "Sign Out"
    @State public var image119Path: String = "image119_4653"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView167(text89Text: text89Text)
            Image(image119Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 6, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView166_Previews: PreviewProvider {
    static var previews: some View {
        CustomView166()
    }
}
