//
//  CustomView146.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView146: View {
    @State public var text85Text: String = "Profile Settings"
    @State public var image111Path: String = "image111_4600"
    var body: some View {
        HStack(alignment: .center, spacing: 173) {
            CustomView147(text85Text: text85Text)
            Image(image111Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 24, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView146_Previews: PreviewProvider {
    static var previews: some View {
        CustomView146()
    }
}
