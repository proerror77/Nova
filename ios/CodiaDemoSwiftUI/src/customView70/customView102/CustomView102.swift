//
//  CustomView102.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView102: View {
    @State public var text67Text: String = "Edit profile"
    @State public var text68Text: String = "Share profile"
    @State public var image84Path: String = "image84_4498"
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CustomView103(text67Text: text67Text)
                .frame(width: 157, height: 35)
            CustomView104(text68Text: text68Text)
                .frame(width: 157, height: 35)
            Image(image84Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 35, height: 35, alignment: .topLeading)
                .cornerRadius(6)
        }
        .frame(width: 365, height: 35, alignment: .topLeading)
    }
}

struct CustomView102_Previews: PreviewProvider {
    static var previews: some View {
        CustomView102()
    }
}
