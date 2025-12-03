//
//  CustomView621.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView621: View {
    @State public var image430Path: String = "image430_42042"
    @State public var text294Text: String = "4"
    @State public var text295Text: String = "Lucy Liu"
    @State public var text296Text: String = "Morgan Stanley"
    @State public var text297Text: String = "2293"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(image430Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView622(text294Text: text294Text)
                .frame(width: 35, height: 35)
            CustomView624(
                text295Text: text295Text,
                text296Text: text296Text)
                .frame(width: 99, height: 38)
            CustomView625(text297Text: text297Text)
                .frame(width: 125)
        }
        .padding(EdgeInsets(top: 27, leading: 15, bottom: 27, trailing: 15))
        .frame(height: 371, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView621_Previews: PreviewProvider {
    static var previews: some View {
        CustomView621()
    }
}
