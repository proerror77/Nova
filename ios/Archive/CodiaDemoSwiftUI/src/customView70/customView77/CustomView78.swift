//
//  CustomView78.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView78: View {
    @State public var text45Text: String = "Bruce Li"
    @State public var image70Path: String = "image70_I441241875"
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Text(text45Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 21))
                .lineLimit(1)
                .frame(width: 83, alignment: .leading)
                .multilineTextAlignment(.leading)
            Image(image70Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 5, alignment: .topLeading)
        }
        .frame(width: 100, height: 16, alignment: .top)
    }
}

struct CustomView78_Previews: PreviewProvider {
    static var previews: some View {
        CustomView78()
    }
}
