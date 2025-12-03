//
//  CustomView422.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView422: View {
    @State public var image268Path: String = "image268_41360"
    @State public var text221Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView423(
                image268Path: image268Path,
                text221Text: text221Text)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 310, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 37))
    }
}

struct CustomView422_Previews: PreviewProvider {
    static var previews: some View {
        CustomView422()
    }
}
