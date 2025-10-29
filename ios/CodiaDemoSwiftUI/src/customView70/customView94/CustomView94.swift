//
//  CustomView94.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView94: View {
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
        HStack(alignment: .center, spacing: 10) {
            CustomView95(
                image80Path: image80Path,
                text62Text: text62Text,
                text63Text: text63Text,
                image81Path: image81Path,
                image82Path: image82Path,
                text64Text: text64Text,
                text65Text: text65Text,
                image83Path: image83Path,
                text66Text: text66Text)
                .frame(width: 175)
        }
        .padding(EdgeInsets(top: 6, leading: 5, bottom: 6, trailing: 5))
        .frame(width: 185, height: 278, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CustomView94_Previews: PreviewProvider {
    static var previews: some View {
        CustomView94()
    }
}
