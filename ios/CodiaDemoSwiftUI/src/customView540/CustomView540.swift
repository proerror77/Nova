//
//  CustomView540.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView540: View {
    @State public var text257Text: String = "Go to the Account center"
    @State public var image376Path: String = "image376_41857"
    @State public var text258Text: String = "Account_one (Primary)"
    @State public var image377Path: String = "image377_41859"
    @State public var image378Path: String = "image378_41863"
    @State public var text259Text: String = "Add an alias account (Anonymous)"
    @State public var image379Path: String = "image379_41868"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .frame(width: 393, height: 334)
            Rectangle()
                .fill(Color(red: 0.82, green: 0.11, blue: 0.26, opacity: 1.00))
                .clipShape(RoundedRectangle(cornerRadius: 3.5))
                .frame(width: 56, height: 7)
                .offset(x: 168, y: 8)
            CustomView543(text257Text: text257Text)
                .frame(width: 339, height: 33)
                .offset(x: 27, y: 192)
            CustomView544(
                image376Path: image376Path,
                text258Text: text258Text,
                image377Path: image377Path,
                image378Path: image378Path,
                text259Text: text259Text)
                .frame(width: 339, height: 127)
                .offset(x: 27, y: 43)
            Image(image379Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 102, height: 70, alignment: .topLeading)
                .offset(x: 145, y: 247)
        }
        .frame(width: 393, height: 334, alignment: .topLeading)
    }
}

struct CustomView540_Previews: PreviewProvider {
    static var previews: some View {
        CustomView540()
    }
}
