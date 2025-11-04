//
//  CustomView430.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView430: View {
    @State public var image271Path: String = "image271_41373"
    @State public var text223Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView431(
                image271Path: image271Path,
                text223Text: text223Text)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 310, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 37))
    }
}

struct CustomView430_Previews: PreviewProvider {
    static var previews: some View {
        CustomView430()
    }
}
