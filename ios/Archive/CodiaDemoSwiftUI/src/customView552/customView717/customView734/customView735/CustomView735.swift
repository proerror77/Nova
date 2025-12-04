//
//  CustomView735.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView735: View {
    @State public var image514Path: String = "image514_42325"
    @State public var text350Text: String = "3"
    @State public var text351Text: String = "Lucy Liu"
    @State public var text352Text: String = "Morgan Stanley"
    @State public var text353Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView736(
                image514Path: image514Path,
                text350Text: text350Text,
                text351Text: text351Text,
                text352Text: text352Text,
                text353Text: text353Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView735_Previews: PreviewProvider {
    static var previews: some View {
        CustomView735()
    }
}
