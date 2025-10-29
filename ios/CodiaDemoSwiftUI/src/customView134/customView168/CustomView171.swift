//
//  CustomView171.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView171: View {
    @State public var text90Text: String = "My Channels"
    @State public var image121Path: String = "image121_4666"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView172(text90Text: text90Text)
            Image(image121Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 6, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView171_Previews: PreviewProvider {
    static var previews: some View {
        CustomView171()
    }
}
