//
//  CustomView142.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView142: View {
    @State public var image110Path: String = "image110_4590"
    @State public var text85Text: String = "Profile Settings"
    @State public var image111Path: String = "image111_4600"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView143(
                image110Path: image110Path,
                text85Text: text85Text,
                image111Path: image111Path)
                .frame(width: 340.891, height: 60)
                .offset(x: 16)
        }
        .frame(width: 356.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView142_Previews: PreviewProvider {
    static var previews: some View {
        CustomView142()
    }
}
