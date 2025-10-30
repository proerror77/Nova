//
//  CustomView115.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView115: View {
    @State public var image95Path: String = "image95_4527"
    @State public var image96Path: String = "image96_4530"
    @State public var text73Text: String = "Received likes and collected "
    @State public var image97Path: String = "image97_4540"
    @State public var text74Text: String = "Number of posts"
    @State public var text75Text: String = "30"
    @State public var image98Path: String = "image98_4547"
    @State public var text76Text: String = "Gain collection points"
    @State public var text77Text: String = "479"
    @State public var image99Path: String = "image99_4554"
    @State public var text78Text: String = "Get the number of likes"
    @State public var text79Text: String = "61"
    @State public var text80Text: String = "OK"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image95Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 394, height: 852, alignment: .topLeading)
            Rectangle()
                .fill(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 0.50))
                .frame(width: 394, height: 852)
            CustomView117(
                image96Path: image96Path,
                text73Text: text73Text,
                image97Path: image97Path,
                text74Text: text74Text,
                text75Text: text75Text,
                image98Path: image98Path,
                text76Text: text76Text,
                text77Text: text77Text,
                image99Path: image99Path,
                text78Text: text78Text,
                text79Text: text79Text,
                text80Text: text80Text)
                .frame(width: 313, height: 338)
                .offset(x: 40, y: 229)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
    }
}

struct CustomView115_Previews: PreviewProvider {
    static var previews: some View {
        CustomView115()
    }
}
