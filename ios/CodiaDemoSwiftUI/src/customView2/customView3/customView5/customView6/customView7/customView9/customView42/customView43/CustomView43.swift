//
//  CustomView43.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView43: View {
    @State public var image25Path: String = "image25_I426841961"
    @State public var text19Text: String = "5"
    @State public var text20Text: String = "Lucy Liu"
    @State public var text21Text: String = "Morgan Stanley"
    @State public var text22Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView44(
                image25Path: image25Path,
                text19Text: text19Text,
                text20Text: text20Text,
                text21Text: text21Text,
                text22Text: text22Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView43_Previews: PreviewProvider {
    static var previews: some View {
        CustomView43()
    }
}
