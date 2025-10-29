//
//  CustomView160.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView160: View {
    @State public var text88Text: String = "Invite Friends"
    @State public var image117Path: String = "image117_4640"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView161(
                text88Text: text88Text,
                image117Path: image117Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView160_Previews: PreviewProvider {
    static var previews: some View {
        CustomView160()
    }
}
