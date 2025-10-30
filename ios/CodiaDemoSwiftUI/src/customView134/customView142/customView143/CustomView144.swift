//
//  CustomView144.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView144: View {
    @State public var text85Text: String = "Profile Settings"
    @State public var image111Path: String = "image111_4600"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView145(
                text85Text: text85Text,
                image111Path: image111Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 319, alignment: .leading)
    }
}

struct CustomView144_Previews: PreviewProvider {
    static var previews: some View {
        CustomView144()
    }
}
