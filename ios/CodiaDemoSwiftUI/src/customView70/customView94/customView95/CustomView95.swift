//
//  CustomView95.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView95: View {
    @State public var image80Path: String = "image80_4474"
    @State public var text62Text: String = "William Rhodes"
    @State public var text63Text: String = "10m"
    @State public var image81Path: String = "image81_4478"
    @State public var image82Path: String = "image82_4481"
    @State public var text64Text: String = "kyleegigstead Cyborg dreams"
    @State public var text65Text: String = "kyleegigstead Cyborg dreams"
    @State public var image83Path: String = "image83_4487"
    @State public var text66Text: String = "2293"
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CustomView96(
                image80Path: image80Path,
                text62Text: text62Text,
                text63Text: text63Text,
                image81Path: image81Path)
            Image(image82Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 223, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(7)
            CustomView99(
                text64Text: text64Text,
                text65Text: text65Text,
                image83Path: image83Path,
                text66Text: text66Text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 175, alignment: .leading)
    }
}

struct CustomView95_Previews: PreviewProvider {
    static var previews: some View {
        CustomView95()
    }
}
