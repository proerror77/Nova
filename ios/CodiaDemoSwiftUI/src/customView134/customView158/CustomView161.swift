//
//  CustomView161.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView161: View {
    @State public var text88Text: String = "Invite Friends"
    @State public var image117Path: String = "image117_4640"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView162(text88Text: text88Text)
            Image(image117Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 6, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView161_Previews: PreviewProvider {
    static var previews: some View {
        CustomView161()
    }
}
