//
//  CustomView246.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView246: View {
    @State public var text139Text: String = "Bruce Li"
    @State public var image179Path: String = "image179_I487241875"
    @State public var image180Path: String = "image180_4873"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView247(
                text139Text: text139Text,
                image179Path: image179Path)
                .frame(width: 100, height: 16)
            Image(image180Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView246_Previews: PreviewProvider {
    static var previews: some View {
        CustomView246()
    }
}
