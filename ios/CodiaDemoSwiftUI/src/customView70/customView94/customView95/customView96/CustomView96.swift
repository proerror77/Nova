//
//  CustomView96.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView96: View {
    @State public var image80Path: String = "image80_4474"
    @State public var text62Text: String = "William Rhodes"
    @State public var text63Text: String = "10m"
    @State public var image81Path: String = "image81_4478"
    var body: some View {
        HStack(alignment: .center, spacing: 106) {
            CustomView97(
                image80Path: image80Path,
                text62Text: text62Text,
                text63Text: text63Text)
            Image(image81Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 5.997, height: 7.996, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView96_Previews: PreviewProvider {
    static var previews: some View {
        CustomView96()
    }
}
