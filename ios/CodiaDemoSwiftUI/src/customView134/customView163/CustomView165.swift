//
//  CustomView165.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView165: View {
    @State public var text89Text: String = "Sign Out"
    @State public var image119Path: String = "image119_4653"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView166(
                text89Text: text89Text,
                image119Path: image119Path)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView165_Previews: PreviewProvider {
    static var previews: some View {
        CustomView165()
    }
}
