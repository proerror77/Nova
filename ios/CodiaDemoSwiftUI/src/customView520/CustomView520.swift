//
//  CustomView520.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView520: View {
    @State public var image344Path: String = "image344_41796"
    @State public var image345Path: String = "image345_I4179753003"
    @State public var image346Path: String = "image346_I4179753008"
    @State public var text252Text: String = "9:41"
    @State public var image347Path: String = "image347_41799"
    @State public var image348Path: String = "image348_41800"
    @State public var image349Path: String = "image349_41801"
    @State public var image350Path: String = "image350_41802"
    @State public var image351Path: String = "image351_41807"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image344Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 578, height: 1266, alignment: .topLeading)
                .offset(x: -69, y: -247)
            CustomView521(
                image345Path: image345Path,
                image346Path: image346Path,
                text252Text: text252Text)
                .frame(width: 393, height: 46.167)
            Image(image347Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40, alignment: .topLeading)
                .offset(x: 244, y: 730)
            Image(image348Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 10, height: 10, alignment: .topLeading)
                .cornerRadius(5)
                .offset(x: 110, y: 8)
            Image(image349Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 6, height: 6, alignment: .topLeading)
                .cornerRadius(3)
                .offset(x: 271, y: 10)
            Image(image350Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64, alignment: .topLeading)
                .offset(x: 156, y: 717)
            Image(image351Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20, alignment: .topLeading)
                .offset(x: 22, y: 66)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView520_Previews: PreviewProvider {
    static var previews: some View {
        CustomView520()
    }
}
