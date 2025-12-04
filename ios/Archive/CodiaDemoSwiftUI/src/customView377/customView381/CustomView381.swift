//
//  CustomView381.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView381: View {
    @State public var image250Path: String = "image250_41275"
    @State public var text206Text: String = "All contacts"
    @State public var text207Text: String = "4"
    @State public var image251Path: String = "image251_41288"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 351, height: 46)
                .offset(y: 7)
            CustomView383(
                image250Path: image250Path,
                text206Text: text206Text,
                text207Text: text207Text,
                image251Path: image251Path)
                .frame(width: 340.891, height: 60)
                .offset(x: 16)
        }
        .frame(width: 356.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView381_Previews: PreviewProvider {
    static var previews: some View {
        CustomView381()
    }
}
