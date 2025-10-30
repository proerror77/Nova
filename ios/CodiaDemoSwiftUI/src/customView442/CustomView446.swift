//
//  CustomView446.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView446: View {
    @State public var image277Path: String = "image277_41399"
    @State public var text227Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView447(
                image277Path: image277Path,
                text227Text: text227Text)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 310, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 37))
    }
}

struct CustomView446_Previews: PreviewProvider {
    static var previews: some View {
        CustomView446()
    }
}
