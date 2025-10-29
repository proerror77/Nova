//
//  CustomView55.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView55: View {
    @State public var image35Path: String = "image35_4291"
    @State public var text26Text: String = "93"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView56(
                image35Path: image35Path,
                text26Text: text26Text)
                .frame(width: 40.43, height: 18.654)
        }
        .frame(width: 40.43, height: 18.654, alignment: .topLeading)
    }
}

struct CustomView55_Previews: PreviewProvider {
    static var previews: some View {
        CustomView55()
    }
}
