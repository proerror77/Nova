//
//  CustomView736.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView736: View {
    @State public var image514Path: String = "image514_42325"
    @State public var text350Text: String = "3"
    @State public var text351Text: String = "Lucy Liu"
    @State public var text352Text: String = "Morgan Stanley"
    @State public var text353Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image514Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView737(text350Text: text350Text)
                .frame(width: 35, height: 35)
            CustomView739(
                text351Text: text351Text,
                text352Text: text352Text)
                .frame(width: 99, height: 38)
            CustomView740(text353Text: text353Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView736_Previews: PreviewProvider {
    static var previews: some View {
        CustomView736()
    }
}
