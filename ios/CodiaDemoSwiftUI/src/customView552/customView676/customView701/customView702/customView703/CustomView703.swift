//
//  CustomView703.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView703: View {
    @State public var image490Path: String = "image490_42244"
    @State public var text334Text: String = "4"
    @State public var text335Text: String = "Lucy Liu"
    @State public var text336Text: String = "Morgan Stanley"
    @State public var text337Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image490Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView704(text334Text: text334Text)
                .frame(width: 35, height: 35)
            CustomView706(
                text335Text: text335Text,
                text336Text: text336Text)
                .frame(width: 99, height: 38)
            CustomView707(text337Text: text337Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView703_Previews: PreviewProvider {
    static var previews: some View {
        CustomView703()
    }
}
