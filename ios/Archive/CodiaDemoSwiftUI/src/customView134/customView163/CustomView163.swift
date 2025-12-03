//
//  CustomView163.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView163: View {
    @State public var image118Path: String = "image118_4643"
    @State public var text89Text: String = "Sign Out"
    @State public var image119Path: String = "image119_4653"
    var body: some View {
        HStack(alignment: .center) {
            Image(image118Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView164(
                text89Text: text89Text,
                image119Path: image119Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView163_Previews: PreviewProvider {
    static var previews: some View {
        CustomView163()
    }
}
