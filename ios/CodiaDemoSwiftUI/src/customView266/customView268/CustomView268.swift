//
//  CustomView268.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView268: View {
    @State public var image194Path: String = "image194_4921"
    @State public var text149Text: String = "Liam"
    @State public var text150Text: String = "Hello, how are you bro~"
    @State public var text151Text: String = "09:41 PM"
    @State public var image195Path: String = "image195_4930"
    @State public var text152Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 76)
            CustomView270(
                image194Path: image194Path,
                text149Text: text149Text,
                text150Text: text150Text,
                text151Text: text151Text,
                image195Path: image195Path,
                text152Text: text152Text)
                .frame(width: 356, height: 72)
                .offset(x: 22)
        }
        .frame(width: 393, height: 76, alignment: .topLeading)
    }
}

struct CustomView268_Previews: PreviewProvider {
    static var previews: some View {
        CustomView268()
    }
}
