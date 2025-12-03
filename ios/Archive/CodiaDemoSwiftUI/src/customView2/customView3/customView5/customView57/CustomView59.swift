//
//  CustomView59.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView59: View {
    @State public var image41Path: String = "image41_4321"
    @State public var text31Text: String = "93"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView60(
                image41Path: image41Path,
                text31Text: text31Text)
                .frame(width: 40.43, height: 18.654)
        }
        .frame(width: 40.43, height: 18.654, alignment: .topLeading)
    }
}

struct CustomView59_Previews: PreviewProvider {
    static var previews: some View {
        CustomView59()
    }
}
