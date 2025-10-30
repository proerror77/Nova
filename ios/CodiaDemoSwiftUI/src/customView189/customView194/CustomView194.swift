//
//  CustomView194.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView194: View {
    @State public var image139Path: String = "image139_4724"
    @State public var text102Text: String = "Add an Icered account"
    @State public var image140Path: String = "image140_4734"
    @State public var image141Path: String = "image141_4736"
    var body: some View {
        HStack(alignment: .center) {
            Image(image139Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView195(
                text102Text: text102Text,
                image140Path: image140Path,
                image141Path: image141Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView194_Previews: PreviewProvider {
    static var previews: some View {
        CustomView194()
    }
}
