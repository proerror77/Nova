//
//  CustomView313.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView313: View {
    @State public var text174Text: String = "Liam"
    @State public var text175Text: String = "Hello, how are you bro~"
    @State public var text176Text: String = "09:41 PM"
    @State public var image213Path: String = "image213_4996"
    @State public var text177Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView314(
                text174Text: text174Text,
                text175Text: text175Text)
                .frame(width: 161, height: 46)
            CustomView315(
                text176Text: text176Text,
                image213Path: image213Path,
                text177Text: text177Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView313_Previews: PreviewProvider {
    static var previews: some View {
        CustomView313()
    }
}
