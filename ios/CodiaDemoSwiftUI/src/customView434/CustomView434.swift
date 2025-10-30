//
//  CustomView434.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView434: View {
    @State public var image273Path: String = "image273_41381"
    @State public var image274Path: String = "image274_41386"
    @State public var text225Text: String = "Search"
    @State public var image275Path: String = "image275_41388"
    @State public var text226Text: String = "Cancel"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 852)
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 113)
            Image(image273Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                .frame(width: 393, height: 1)
                .offset(y: 114)
            CustomView438(
                image274Path: image274Path,
                text225Text: text225Text)
                .frame(width: 310, height: 32)
                .offset(x: 22, y: 72)
            Image(image275Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            CustomView441(text226Text: text226Text)
                .frame(width: 44, height: 20)
                .offset(x: 340, y: 78)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView434_Previews: PreviewProvider {
    static var previews: some View {
        CustomView434()
    }
}
