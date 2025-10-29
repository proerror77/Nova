//
//  CustomView97.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView97: View {
    @State public var image80Path: String = "image80_4474"
    @State public var text62Text: String = "William Rhodes"
    @State public var text63Text: String = "10m"
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            Image(image80Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15, alignment: .topLeading)
                .cornerRadius(7.5)
            CustomView98(
                text62Text: text62Text,
                text63Text: text63Text)
                .frame(width: 40)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView97_Previews: PreviewProvider {
    static var previews: some View {
        CustomView97()
    }
}
