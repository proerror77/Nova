//
//  CustomView653.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView653: View {
    @State public var image454Path: String = "image454_42123"
    @State public var text310Text: String = "3"
    @State public var text311Text: String = "Lucy Liu"
    @State public var text312Text: String = "Morgan Stanley"
    @State public var text313Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView654(
                image454Path: image454Path,
                text310Text: text310Text,
                text311Text: text311Text,
                text312Text: text312Text,
                text313Text: text313Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView653_Previews: PreviewProvider {
    static var previews: some View {
        CustomView653()
    }
}
