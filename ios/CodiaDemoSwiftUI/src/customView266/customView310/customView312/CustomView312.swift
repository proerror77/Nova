//
//  CustomView312.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView312: View {
    @State public var image212Path: String = "image212_4987"
    @State public var text174Text: String = "Liam"
    @State public var text175Text: String = "Hello, how are you bro~"
    @State public var text176Text: String = "09:41 PM"
    @State public var image213Path: String = "image213_4996"
    @State public var text177Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(image212Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: true, vertical: true)
            CustomView313(
                text174Text: text174Text,
                text175Text: text175Text,
                text176Text: text176Text,
                image213Path: image213Path,
                text177Text: text177Text)
                .frame(height: 72)
        }
        .frame(width: 356, height: 72, alignment: .topLeading)
    }
}

struct CustomView312_Previews: PreviewProvider {
    static var previews: some View {
        CustomView312()
    }
}
