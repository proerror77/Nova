//
//  CustomView234.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView234: View {
    @State public var text124Text: String = "Save"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text124Text)
                            .foregroundColor(Color(red: 0.58, green: 0.58, blue: 0.58, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 18))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
        }
        .frame(width: 42, height: 20, alignment: .topLeading)
    }
}

struct CustomView234_Previews: PreviewProvider {
    static var previews: some View {
        CustomView234()
    }
}
