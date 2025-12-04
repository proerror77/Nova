//
//  CustomView424.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView424: View {
    @State public var image268Path: String = "image268_41360"
    @State public var text221Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image268Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18.005, height: 18.002, alignment: .topLeading)
            Text(text221Text)
                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView424_Previews: PreviewProvider {
    static var previews: some View {
        CustomView424()
    }
}
