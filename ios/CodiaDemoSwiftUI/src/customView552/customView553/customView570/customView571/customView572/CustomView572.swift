//
//  CustomView572.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView572: View {
    @State public var image394Path: String = "image394_41921"
    @State public var text270Text: String = "3"
    @State public var text271Text: String = "Lucy Liu"
    @State public var text272Text: String = "Morgan Stanley"
    @State public var text273Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image394Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView573(text270Text: text270Text)
                .frame(width: 35, height: 35)
            CustomView575(
                text271Text: text271Text,
                text272Text: text272Text)
                .frame(width: 99, height: 38)
            CustomView576(text273Text: text273Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView572_Previews: PreviewProvider {
    static var previews: some View {
        CustomView572()
    }
}
