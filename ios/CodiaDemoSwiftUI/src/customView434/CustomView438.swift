//
//  CustomView438.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView438: View {
    @State public var image274Path: String = "image274_41386"
    @State public var text225Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView439(
                image274Path: image274Path,
                text225Text: text225Text)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 310, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 37))
    }
}

struct CustomView438_Previews: PreviewProvider {
    static var previews: some View {
        CustomView438()
    }
}
