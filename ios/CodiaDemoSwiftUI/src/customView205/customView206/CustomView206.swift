//
//  CustomView206.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView206: View {
    @State public var text109Text: String = "Bruce Li"
    @State public var image145Path: String = "image145_I475541875"
    @State public var image146Path: String = "image146_4756"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView207(
                text109Text: text109Text,
                image145Path: image145Path)
                .frame(width: 100, height: 16)
            Image(image146Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView206_Previews: PreviewProvider {
    static var previews: some View {
        CustomView206()
    }
}
