//
//  CustomView170.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView170: View {
    @State public var text90Text: String = "My Channels"
    @State public var image121Path: String = "image121_4666"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView171(
                text90Text: text90Text,
                image121Path: image121Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView170_Previews: PreviewProvider {
    static var previews: some View {
        CustomView170()
    }
}
