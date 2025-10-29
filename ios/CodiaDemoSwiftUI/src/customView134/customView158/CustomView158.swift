//
//  CustomView158.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView158: View {
    @State public var image116Path: String = "image116_4630"
    @State public var text88Text: String = "Invite Friends"
    @State public var image117Path: String = "image117_4640"
    var body: some View {
        HStack(alignment: .center) {
            Image(image116Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView159(
                text88Text: text88Text,
                image117Path: image117Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView158_Previews: PreviewProvider {
    static var previews: some View {
        CustomView158()
    }
}
