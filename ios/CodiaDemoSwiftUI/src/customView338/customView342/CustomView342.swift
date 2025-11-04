//
//  CustomView342.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView342: View {
    @State public var image224Path: String = "image224_41068"
    @State public var text191Text: String = "Search"
    @State public var image225Path: String = "image225_41070"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView343(
                image224Path: image224Path,
                text191Text: text191Text,
                image225Path: image225Path)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 349, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}

struct CustomView342_Previews: PreviewProvider {
    static var previews: some View {
        CustomView342()
    }
}
