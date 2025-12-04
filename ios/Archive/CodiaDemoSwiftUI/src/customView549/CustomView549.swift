//
//  CustomView549.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView549: View {
    @State public var text260Text: String = "Bruce Li"
    @State public var image380Path: String = "image380_41872"
    @State public var text261Text: String = "Bruce Li"
    @State public var image381Path: String = "image381_41875"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView550(
                text260Text: text260Text,
                image380Path: image380Path)
                .frame(width: 100, height: 16)
                .offset(x: 20, y: 55)
            CustomView551(
                text261Text: text261Text,
                image381Path: image381Path)
                .frame(width: 100, height: 16)
                .offset(x: 20, y: 20)
        }
        .frame(width: 140, height: 91, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 0.54, green: 0.22, blue: 0.96, opacity: 1.00), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .clipped()
    }
}

struct CustomView549_Previews: PreviewProvider {
    static var previews: some View {
        CustomView549()
    }
}
