//
//  CustomView388.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView388: View {
    @State public var text207Text: String = "4"
    @State public var image251Path: String = "image251_41288"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView389(text207Text: text207Text)
            Image(image251Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 5, height: 10, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 24, alignment: .leading)
    }
}

struct CustomView388_Previews: PreviewProvider {
    static var previews: some View {
        CustomView388()
    }
}
