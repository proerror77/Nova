//
//  CustomView354.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView354: View {
    @State public var image230Path: String = "image230_41106"
    @State public var text195Text: String = "Bruce Li (you)"
    @State public var text196Text: String = "+86 199xxxx6164"
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(image230Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50, alignment: .topLeading)
                .cornerRadius(25)
            CustomView355(
                text195Text: text195Text,
                text196Text: text196Text)
                .frame(width: 105)
        }
        .frame(height: 47, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView354_Previews: PreviewProvider {
    static var previews: some View {
        CustomView354()
    }
}
