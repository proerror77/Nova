//
//  CustomView595.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView595: View {
    @State public var image412Path: String = "image412_41982"
    @State public var text282Text: String = "1"
    @State public var text283Text: String = "Lucy Liu"
    @State public var text284Text: String = "Morgan Stanley"
    @State public var text285Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView596(
                image412Path: image412Path,
                text282Text: text282Text,
                text283Text: text283Text,
                text284Text: text284Text,
                text285Text: text285Text)
                .frame(width: 309, height: 389)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView595_Previews: PreviewProvider {
    static var previews: some View {
        CustomView595()
    }
}
