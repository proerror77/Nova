//
//  CustomView571.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView571: View {
    @State public var image394Path: String = "image394_41921"
    @State public var text270Text: String = "3"
    @State public var text271Text: String = "Lucy Liu"
    @State public var text272Text: String = "Morgan Stanley"
    @State public var text273Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView572(
                image394Path: image394Path,
                text270Text: text270Text,
                text271Text: text271Text,
                text272Text: text272Text,
                text273Text: text273Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView571_Previews: PreviewProvider {
    static var previews: some View {
        CustomView571()
    }
}
